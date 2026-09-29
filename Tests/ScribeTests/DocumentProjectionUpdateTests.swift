#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class DocumentProjectionUpdateTests: XCTestCase {
    func testLocalSplitMatchesFullProjectionAndPreservesUnrelatedAttributes() throws {
        var before = ScribeDocument(); before.sections[0].paragraphs = [Paragraph("First"), Paragraph("Middle text"), Paragraph("Last")]
        var after = before
        _ = try after.splitTrackedParagraph(id: before.paragraphs[1].id, range: NSRange(location: 6, length: 0), author: .init(name: "Writer"))
        let storage = NSTextStorage(attributedString: AttributedDocument.render(before))
        let marker = NSAttributedString.Key("test.unrelated")
        storage.addAttribute(marker, value: "retained", range: NSRange(location: 0, length: 5))
        XCTAssertEqual(DocumentProjectionUpdate.apply(from: before, to: after, storage: storage), 12)
        XCTAssertEqual(storage.attribute(marker, at: 0, effectiveRange: nil) as? String, "retained")
        let expected = AttributedDocument.capture(AttributedDocument.render(after), preserving: after)
        XCTAssertEqual(AttributedDocument.capture(storage, preserving: after).paragraphs, expected.paragraphs)
        XCTAssertNotNil(DocumentProjectionUpdate.apply(from: after, to: before, storage: storage))
        XCTAssertEqual(storage.string, "First\nMiddle text\nLast")
        XCTAssertEqual(storage.attribute(marker, at: 0, effectiveRange: nil) as? String, "retained")
    }
    func testEmptyFinalParagraphAndTrailingSeparatorMatchFullProjection() throws {
        for text in ["", "End"] {
            var before = ScribeDocument(); before.sections[0].paragraphs = [Paragraph("First"), Paragraph(text, style: "caption")]
            var after = before
            _ = try after.splitTrackedParagraph(id: before.paragraphs[1].id, range: NSRange(location: text.utf16.count, length: 0), author: .init(name: "Writer"))
            let storage = NSTextStorage(attributedString: AttributedDocument.render(before))
            XCTAssertNotNil(DocumentProjectionUpdate.apply(from: before, to: after, storage: storage))
            XCTAssertEqual(storage.string, AttributedDocument.render(after).string)
            let attributes = AttributedDocument.editingAttributes(for: after.paragraphs.last!, in: after)
            let actual = AttributedDocument.capture(storage, preserving: after, typingAttributes: attributes)
            let expected = AttributedDocument.capture(AttributedDocument.render(after), preserving: after, typingAttributes: attributes)
            XCTAssertEqual(actual.paragraphs, expected.paragraphs)
        }
    }
    func testCommentSpansAndStaleProjectionUseFullPathWithoutMutation() throws {
        var before = ScribeDocument(); before.sections[0].paragraphs[0] = Paragraph("Annotated text")
        before.comments = [.init(anchor: .init(paragraphID: before.paragraphs[0].id, offset: 0, length: 14), text: "Comment", author: "Reader")]
        var after = before
        _ = try after.splitTrackedParagraph(id: before.paragraphs[0].id, range: NSRange(location: 10, length: 0), author: .init(name: "Writer"))
        let projected = AttributedDocument.render(before), storage = NSTextStorage(attributedString: projected)
        XCTAssertNil(DocumentProjectionUpdate.apply(from: before, to: after, storage: storage))
        XCTAssertTrue(storage.isEqual(to: projected))
        before.comments = []; after.comments = []
        storage.setAttributedString(NSAttributedString(string: "Unrelated native content"))
        XCTAssertNil(DocumentProjectionUpdate.apply(from: before, to: after, storage: storage))
        XCTAssertEqual(storage.string, "Unrelated native content")
    }
}
#endif
