import Foundation
import XCTest
@testable import DocumentCore

final class ListReviewTests: XCTestCase {
    private let author = RevisionAuthor(name: "Writer")
    private func document(_ text: String) -> ScribeDocument {
        var document = ScribeDocument(); var paragraph = Paragraph(text)
        paragraph.list = .init(kind: .decimal, start: 4, restart: true)
        document.sections[0].paragraphs = [paragraph]; return document
    }
    func testReturnRetainsSelectedTextAndRejectRestoresItem() throws {
        var document = document("First second"), before = document
        document.comments = [.init(anchor: .init(paragraphID: document.paragraphs[0].id, offset: 6, length: 6), text: "Keep", author: "Reader")]
        before = document
        let target = try document.splitTrackedListItem(id: document.paragraphs[0].id, range: NSRange(location: 5, length: 1), author: author)
        XCTAssertEqual(document.paragraphs.map(\.text), ["First ", "second"])
        XCTAssertEqual(document.paragraphs[1].id, target)
        XCTAssertNil(document.paragraphs[1].list?.restart)
        XCTAssertEqual(document.comments[0].anchor.paragraphID, target)
        XCTAssertEqual(document.pendingRevisionIDs.count, 2)
        try document.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document.paragraphs, before.paragraphs)
        XCTAssertEqual(document.comments, before.comments)
    }
    func testExistingSeparatorReviewMovesToContinuationOnly() throws {
        var document = document("AB"), end = Paragraph("End"), separator = RunReview()
        separator.deletion = .init(author: author)
        document.sections[0].paragraphs[0].breakReview = separator
        document.sections[0].paragraphs.append(end)
        _ = try document.splitTrackedListItem(id: document.paragraphs[0].id, range: NSRange(location: 1, length: 0), author: author)
        XCTAssertNotNil(document.paragraphs[0].breakReview?.insertion)
        XCTAssertNil(document.paragraphs[0].breakReview?.deletion)
        XCTAssertEqual(document.paragraphs[1].breakReview, separator)
        XCTAssertEqual(document.paragraphs[2].id, end.id)
        try NativeFormat.validate(document)
    }
    func testSplitWithPendingListFormattingKeepsHistoryAndCanRejectBreak() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs[0] = Paragraph("AB")
        let before = document
        document.sections[0].paragraphs[0].list = .init(kind: .decimal, start: 5, restart: true)
        try document.recordParagraphFormattingChanges(from: before, identity: .init(author: author))
        let format = document.pendingRevisionIDs[0]
        _ = try document.splitTrackedListItem(id: document.paragraphs[0].id, range: NSRange(location: 1, length: 0), author: author)
        XCTAssertEqual(document.paragraphs[1].formattingReview?.pendingIDs, [format])
        let separator = try XCTUnwrap(document.paragraphs[0].breakReview?.insertion?.id)
        try document.resolveRevision(separator, accepting: false)
        XCTAssertEqual(document.paragraphs.count, 1); XCTAssertEqual(document.paragraphs[0].text, "AB")
        XCTAssertEqual(document.pendingRevisionIDs, [format])
        try document.resolveRevision(format, accepting: false)
        XCTAssertNil(document.paragraphs[0].list)
    }
    func testReplacingOwnDraftWithReturnRemovesDraftWithoutDeletion() throws {
        var document = document("draft"), review = RunReview(); review.insertion = .init(author: author)
        document.sections[0].paragraphs[0].runs[0].review = review
        _ = try document.splitTrackedListItem(id: document.paragraphs[0].id, range: NSRange(location: 0, length: 5), author: author)
        XCTAssertEqual(document.paragraphs.map(\.text), ["", ""])
        XCTAssertEqual(document.pendingRevisionIDs.count, 1)
        try document.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document.paragraphs.count, 1)
        XCTAssertEqual(document.paragraphs[0].text, "")
    }
    func testEmptyReturnTracksOutdentAndInvalidUnicodeIsAtomic() throws {
        var document = document("")
        let original = document
        _ = try document.splitTrackedListItem(id: document.paragraphs[0].id, range: NSRange(location: 0, length: 0), author: author)
        XCTAssertNil(document.paragraphs[0].list); XCTAssertEqual(document.pendingRevisionIDs.count, 1)
        try document.resolveAllRevisions(accepting: false); XCTAssertEqual(document, original)
        document = self.document("👩🏽‍💻")
        let unicode = document
        XCTAssertThrowsError(try document.splitTrackedListItem(id: document.paragraphs[0].id, range: NSRange(location: 1, length: 0), author: author))
        XCTAssertEqual(document, unicode)
    }
}
