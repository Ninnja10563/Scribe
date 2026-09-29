import Foundation
import XCTest
@testable import DocumentCore

final class TrackedParagraphSplitTests: XCTestCase {
    func testSplitProjectsFirstOnlyPageBreakHistoryAndRejectRestores() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs[0] = Paragraph("Before after")
        let original = document, author = RevisionAuthor(name: "Writer")
        document.sections[0].paragraphs[0].pageBreakBefore = true
        try document.recordParagraphFormattingChanges(from: original, identity: .init(author: author))
        let formatted = document
        _ = try document.splitTrackedParagraph(id: document.paragraphs[0].id, range: NSRange(location: 7, length: 0), author: author)
        XCTAssertEqual(document.paragraphs.map(\.text), ["Before ", "after"])
        XCTAssertTrue(document.paragraphs[0].pageBreakBefore); XCTAssertFalse(document.paragraphs[1].pageBreakBefore)
        XCTAssertNil(document.paragraphs[1].formattingReview)
        let split = try XCTUnwrap(document.paragraphs[0].breakReview?.insertion?.id)
        try document.resolveRevision(split, accepting: false)
        XCTAssertEqual(document, formatted)
    }
    func testEmptyOrdinaryParagraphReturnCreatesTrackedBoundary() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs[0].runs[0].format.italic = true
        let before = document
        _ = try document.splitTrackedParagraph(id: document.paragraphs[0].id, range: NSRange(location: 0, length: 0), author: .init(name: "Writer"))
        XCTAssertEqual(document.paragraphs.count, 2)
        XCTAssertEqual(document.paragraphs[1].runs[0].format.italic, true)
        XCTAssertEqual(document.pendingRevisionIDs.count, 1)
        try document.resolveAllRevisions(accepting: false)
        XCTAssertEqual(document, before)
    }
}
