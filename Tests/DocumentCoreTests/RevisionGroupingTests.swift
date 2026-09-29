import Foundation
import XCTest
@testable import DocumentCore

final class RevisionGroupingTests: XCTestCase {
    private let author = RevisionAuthor(name: "Writer")
    private func pastedDocument() throws -> (ScribeDocument, ScribeDocument, UUID, UUID) {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("AB")]
        let original = document
        document.sections[0].paragraphs[0].styleID = "heading2"
        let older = RevisionIdentity(author: .init(name: "Earlier reviewer"))
        try document.recordParagraphFormattingChanges(from: original, identity: older)
        let beforePaste = document
        var title = Paragraph(); title.styleID = "title"
        var quote = Paragraph(); quote.styleID = "quote"
        _ = try document.replaceTrackedRange(.init(paragraphID: document.paragraphs[0].id, offset: 1, length: 0),
            withLines: [[TextRun("X")], [TextRun("Y")]], paragraphProperties: [ParagraphRevisionState(title), ParagraphRevisionState(quote)], author: author)
        return (document, beforePaste, older.id, try XCTUnwrap(document.paragraphs[0].breakReview?.insertion?.id))
    }
    func testRejectingGroupedInsertionRestoresOlderParagraphHistoryAndInheritance() throws {
        var (document, before, older, insertion) = try pastedDocument()
        XCTAssertEqual(document.paragraphs.map(\.styleID), ["title", "quote"])
        XCTAssertEqual(try NativeFormat.decode(NativeFormat.encode(document)), document)
        try document.resolveRevision(insertion, accepting: false)
        XCTAssertEqual(document.paragraphs, before.paragraphs)
        XCTAssertEqual(document.pendingRevisionIDs, [older])
    }
    func testAcceptedPasteFormattingSurvivesRejectionOfOlderFormatting() throws {
        var (document, _, older, insertion) = try pastedDocument()
        try document.resolveRevision(insertion, accepting: true)
        XCTAssertEqual(document.pendingRevisionIDs, [older])
        try document.resolveRevision(older, accepting: false)
        XCTAssertEqual(document.paragraphs.map(\.text), ["AX", "YB"])
        XCTAssertEqual(document.paragraphs.map(\.styleID), ["title", "quote"])
        XCTAssertFalse(document.hasPendingRevisions)
    }
    func testDeletingOneGroupedSeparatorKeepsOtherComponentsAndRejectsCleanly() throws {
        var (document, before, older, insertion) = try pastedDocument()
        XCTAssertTrue(try document.removeOwnInsertedSeparator(after: document.paragraphs[0].id, authorID: author.id))
        XCTAssertEqual(document.paragraphs.map(\.text), ["AXYB"])
        XCTAssertTrue(document.pendingRevisionIDs.contains(insertion))
        try document.resolveRevision(insertion, accepting: false)
        XCTAssertEqual(document.paragraphs, before.paragraphs)
        XCTAssertEqual(document.pendingRevisionIDs, [older])
    }
    func testReplacingAcrossGroupedBoundaryDoesNotFreezeOriginalCharacterStyle() throws {
        var (document, before, _, _) = try pastedDocument()
        var selection = TextAnchor(paragraphID: document.paragraphs[0].id, offset: 1, length: 0)
        selection.endParagraphID = document.paragraphs[1].id; selection.endOffset = 1
        _ = try document.replaceTrackedRange(selection, with: [TextRun("Z")], author: author)
        XCTAssertEqual(document.paragraphs.map(\.text), ["AZB"])
        try document.resolveAllRevisions(accepting: false)
        try before.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document.paragraphs, before.paragraphs)
    }
    func testGroupedDraftJoinProtectsAnIndependentAcceptedFormat() throws {
        var (document, _, _, _) = try pastedDocument()
        let beforeFormat = document, other = RevisionIdentity(author: .init(name: "Other"))
        document.sections[0].paragraphs[1].styleID = "heading3"
        try document.recordParagraphFormattingChanges(from: beforeFormat, identity: other)
        try document.resolveRevision(other.id, accepting: true)
        let before = document
        XCTAssertThrowsError(try document.removeOwnInsertedSeparator(after: document.paragraphs[0].id, authorID: author.id))
        XCTAssertEqual(document, before)
    }
    func testGroupCannotMixAuthorsOrDatesOrReuseAnIdentityForDifferentKinds() throws {
        let (source, _, _, _) = try pastedDocument()
        var document = source
        let index = try XCTUnwrap(document.paragraphs[0].formattingReview?.changes.indices.last)
        document.sections[0].paragraphs[0].formattingReview!.changes[index].identity.author.name = "Impersonated"
        XCTAssertThrowsError(try NativeFormat.validate(document))
        document = source
        document.sections[0].paragraphs[0].formattingReview!.changes[index].identity.date.addTimeInterval(1)
        XCTAssertThrowsError(try NativeFormat.validate(document))
        document = source
        document.sections[0].paragraphs[0].formattingReview!.changes[index].identity = try XCTUnwrap(source.paragraphs[0].breakReview?.insertion)
        XCTAssertThrowsError(try NativeFormat.validate(document))
    }
    func testLegacyUngroupedIdentityDecodesWithoutGroupMetadata() throws {
        let identity = RevisionIdentity(author: author)
        let data = try JSONEncoder().encode(identity)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("groupID"))
        XCTAssertNil(try JSONDecoder().decode(RevisionIdentity.self, from: data).groupID)
    }
}
