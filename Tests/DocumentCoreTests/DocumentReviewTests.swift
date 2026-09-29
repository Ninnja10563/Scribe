import Foundation
import XCTest
@testable import DocumentCore

final class DocumentReviewTests: XCTestCase {
    func testAcceptingDisjointDeletionsRebasesCommentsAndKeepsDetachedText() throws {
        let author = RevisionAuthor(name: "Reviewer"), revision = RevisionIdentity(author: .init(name: "Reviewer"))
        var second = TextRun("two "), fourth = TextRun("four")
        var review = RunReview(); review.deletion = revision
        second.review = review; fourth.review = review
        var document = ScribeDocument()
        document.sections[0].paragraphs[0].runs = [TextRun("one "), second, TextRun("three "), fourth]
        let paragraphID = document.paragraphs[0].id
        document.comments = [
            Comment(anchor: .init(paragraphID: paragraphID, offset: 8, length: 5), text: "Keep this", author: author.name),
            Comment(anchor: .init(paragraphID: paragraphID, offset: 4, length: 3), text: "Deleted source comment", author: author.name),
            Comment(anchor: .init(paragraphID: paragraphID, offset: 2, length: 13), text: "Spans edits", author: author.name)
        ]
        try document.resolveRevision(revision.id, accepting: true)
        XCTAssertEqual(document.paragraphs[0].text, "one three ")
        XCTAssertEqual(document.comments[0].anchor.offset, 4); XCTAssertEqual(document.comments[0].anchor.length, 5)
        XCTAssertEqual(document.comments[1].isDetached, true); XCTAssertEqual(document.comments[1].text, "Deleted source comment")
        XCTAssertEqual(document.comments[2].anchor.offset, 2); XCTAssertEqual(document.comments[2].anchor.length, 8)
        XCTAssertEqual(document.paragraphs[0].id, paragraphID); XCTAssertFalse(document.hasPendingRevisions)
    }
    func testNoteReferenceDeletionIsReversibleUntilAccepted() throws {
        var document = ScribeDocument()
        let note = DocumentNote(kind: .footnote, text: "Source")
        let deletion = RevisionIdentity(author: .init(name: "Reviewer"))
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        var review = RunReview(); review.deletion = deletion; reference.review = review
        document.notes = [note]; document.sections[0].paragraphs[0].runs = [TextRun("Body"), reference]
        var rejected = document; try rejected.resolveAllRevisions(accepting: false)
        XCTAssertEqual(rejected.notes, [note]); XCTAssertEqual(rejected.paragraphs[0].runs.last?.noteID, note.id)
        XCTAssertFalse(rejected.hasPendingRevisions)
        try document.resolveAllRevisions(accepting: true)
        XCTAssertTrue(document.notes.isEmpty); XCTAssertEqual(document.paragraphs[0].text, "Body")
    }
    func testDecisionsReachNoteContentAndPreserveNativeRoundTrip() throws {
        let author = RevisionAuthor(name: "Reviewer")
        var text = RevisionText(runs: [TextRun("Old citation")])
        try text.replace(NSRange(location: 0, length: 3), with: [TextRun("New")], insertion: .init(author: author), deletion: .init(author: author))
        var note = DocumentNote(kind: .endnote); note.paragraphs[0].runs = text.runs
        var reference = TextRun("\u{fffc}"); reference.noteID = note.id
        var document = ScribeDocument(); document.notes = [note]; document.sections[0].paragraphs[0].runs = [reference]
        document = try NativeFormat.decode(NativeFormat.encode(document))
        XCTAssertEqual(document.pendingRevisionIDs.count, 2)
        try document.resolveAllRevisions(accepting: true)
        XCTAssertEqual(document.notes[0].plainText, "New citation"); XCTAssertFalse(document.hasPendingRevisions)
        try NativeFormat.validate(document)
    }
    func testInvalidInputCannotPartiallyResolveDocument() throws {
        var document = ScribeDocument(), run = TextRun("Text")
        var review = RunReview(); review.deletion = .init(author: .init(name: "Reviewer")); review.formattingBase = TextFormatting()
        run.review = review; document.sections[0].paragraphs[0].runs = [run]
        let before = document
        XCTAssertThrowsError(try document.resolveAllRevisions(accepting: true))
        XCTAssertEqual(document, before)
    }
}
