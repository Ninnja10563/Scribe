import Foundation
import XCTest
@testable import DocumentCore

final class ParagraphFormattingReviewTests: XCTestCase {
    private func edit(_ document: inout ScribeDocument, _ change: (inout Paragraph, ScribeDocument) -> Void) throws -> UUID {
        let before = document.paragraphs[0], identity = RevisionIdentity(author: .init(name: "Reviewer"))
        var after = before; change(&after, document)
        try after.recordFormattingChange(from: before, identity: identity,
            inheritedBefore: document.style(for: before).paragraph, inheritedAfter: document.style(for: after).paragraph)
        document.sections[0].paragraphs[0] = after
        try NativeFormat.validate(document)
        return identity.id
    }
    func testRejectEarlierAlignmentPreservesAcceptedLaterSpacingAndText() throws {
        var document = ScribeDocument(); document.sections[0].paragraphs = [Paragraph("Original")]
        let alignment = try edit(&document) { paragraph, model in
            var format = model.style(for: paragraph).paragraph; format.alignment = .center; paragraph.formatting = format
        }
        let spacing = try edit(&document) { paragraph, _ in paragraph.formatting!.lineSpacing = 14 }
        document.sections[0].paragraphs[0].runs = [TextRun("Edited after formatting")]
        try document.resolveRevision(spacing, accepting: true)
        XCTAssertEqual(document.pendingRevisionIDs, [alignment])
        try document.resolveRevision(alignment, accepting: false)
        XCTAssertEqual(document.paragraphs[0].formatting?.alignment, .left)
        XCTAssertEqual(document.paragraphs[0].formatting?.lineSpacing, 14)
        XCTAssertEqual(document.paragraphs[0].text, "Edited after formatting")
        XCTAssertNil(document.paragraphs[0].formattingReview)
    }
    func testRejectStyleKeepsLaterGeometryWithoutHeadingDefaults() throws {
        var document = ScribeDocument()
        let style = try edit(&document) { paragraph, _ in paragraph.styleID = "heading1" }
        let geometry = try edit(&document) { paragraph, model in
            var format = model.style(for: paragraph).paragraph; format.headIndent = 36; paragraph.formatting = format
        }
        try document.resolveRevision(style, accepting: false)
        XCTAssertEqual(document.paragraphs[0].styleID, "normal")
        XCTAssertEqual(document.paragraphs[0].formatting?.headIndent, 36)
        XCTAssertEqual(document.paragraphs[0].formatting?.spaceBefore, 0)
        try document.resolveRevision(geometry, accepting: false)
        XCTAssertNil(document.paragraphs[0].formatting)
    }
    func testListAndPageBreakResolveIndependentlyAndRoundTrip() throws {
        var document = ScribeDocument()
        let list = try edit(&document) { paragraph, _ in paragraph.list = .init(kind: .lowerRoman, level: 2, start: 4) }
        let page = try edit(&document) { paragraph, _ in paragraph.pageBreakBefore = true }
        document = try NativeFormat.decode(NativeFormat.encode(document))
        XCTAssertTrue(document.hasPendingRevisions)
        try document.resolveRevision(list, accepting: false)
        XCTAssertNil(document.paragraphs[0].list); XCTAssertTrue(document.paragraphs[0].pageBreakBefore)
        try document.resolveRevision(page, accepting: true)
        XCTAssertFalse(document.hasPendingRevisions)
    }
    func testStyleDefinitionChangeDoesNotRewriteRecordedGeometryDelta() throws {
        var document = ScribeDocument()
        let alignment = try edit(&document) { paragraph, model in
            var format = model.style(for: paragraph).paragraph; format.alignment = .right; paragraph.formatting = format
        }
        document.styles[0].paragraph.lineSpacing = 20
        try NativeFormat.validate(document)
        XCTAssertEqual(document.paragraphs[0].formatting?.lineSpacing, 3)
        try document.resolveRevision(alignment, accepting: false)
        XCTAssertNil(document.paragraphs[0].formatting)
        XCTAssertEqual(document.style(for: document.paragraphs[0]).paragraph.lineSpacing, 20)
    }
    func testGeometryAfterLiveStyleUpdateUsesUpdatedDefaults() throws {
        var document = ScribeDocument()
        let style = try edit(&document) { paragraph, _ in paragraph.styleID = "heading1" }
        let heading = try XCTUnwrap(document.styles.firstIndex { $0.id == "heading1" })
        document.styles[heading].paragraph.lineSpacing = 20
        _ = try edit(&document) { paragraph, model in
            var format = model.style(for: paragraph).paragraph; format.headIndent = 36; paragraph.formatting = format
        }
        XCTAssertEqual(document.paragraphs[0].formatting?.lineSpacing, 20)
        try document.resolveRevision(style, accepting: false)
        XCTAssertEqual(document.paragraphs[0].formatting?.lineSpacing, 3)
        XCTAssertEqual(document.paragraphs[0].formatting?.headIndent, 36)
    }
    func testInvalidHistoryRejectsAtomically() throws {
        var document = ScribeDocument()
        let id = try edit(&document) { paragraph, _ in paragraph.pageBreakBefore = true }
        document.sections[0].paragraphs[0].formattingReview!.changes[0].inheritedBefore.lineSpacing = .infinity
        let before = document
        XCTAssertThrowsError(try document.resolveRevision(id, accepting: false))
        XCTAssertEqual(document, before)
    }
    func testJoiningCannotSilentlyDropPendingParagraphHistory() throws {
        var document = ScribeDocument()
        let formatting = try edit(&document) { paragraph, _ in paragraph.pageBreakBefore = true }
        let second = document.paragraphs[0]
        var first = Paragraph("First"), review = RunReview()
        let deletion = RevisionIdentity(author: .init(name: "Reviewer")); review.deletion = deletion; first.breakReview = review
        document.sections[0].paragraphs = [first, second]
        let before = document
        XCTAssertThrowsError(try document.resolveRevision(deletion.id, accepting: true))
        XCTAssertEqual(document, before)
        try document.resolveRevision(formatting, accepting: false)
        try document.resolveRevision(deletion.id, accepting: true)
        XCTAssertEqual(document.paragraphs.count, 1)
    }
}
