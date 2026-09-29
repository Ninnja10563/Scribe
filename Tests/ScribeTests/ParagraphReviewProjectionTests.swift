#if canImport(AppKit)
import AppKit
import XCTest
import DocumentCore
@testable import Scribe

@MainActor final class ParagraphReviewProjectionTests: XCTestCase {
    func testTrackedSeparatorsSurviveNativeProjectionIncludingEmptyParagraphs() throws {
        _ = NSApplication.shared
        var document = ScribeDocument(), first = Paragraph("Heading", style: "heading1"), empty = Paragraph("")
        var review = RunReview(); review.deletion = RevisionIdentity(author: .init(name: "Reviewer"))
        first.breakReview = review; empty.breakReview = review
        document.sections[0].paragraphs = [first, empty, Paragraph("Final")]
        let rendered = AttributedDocument.render(document)
        let captured = AttributedDocument.capture(rendered, preserving: document)
        try NativeFormat.validate(captured)
        XCTAssertEqual(captured.paragraphs.map(\.breakReview), document.paragraphs.map(\.breakReview))
        XCTAssertEqual(captured.paragraphs.map(\.text), ["Heading", "", "Final"])
        let string = rendered.string as NSString
        for index in 0..<rendered.length where string.character(at: index) != 10 {
            XCTAssertNil(rendered.attribute(.scribeBreakReview, at: index, effectiveRange: nil), "Separator metadata must not leak into text")
        }
    }
    func testMergedHeadingKeepsRenderedFontWhileItsParagraphStyleChanges() throws {
        _ = NSApplication.shared
        var document = ScribeDocument(), first = Paragraph("Body "), second = Paragraph("Heading", style: "heading1")
        var review = RunReview(); review.deletion = RevisionIdentity(author: .init(name: "Reviewer")); first.breakReview = review
        document.sections[0].paragraphs = [first, second]
        let original = AttributedDocument.render(document)
        let originalFont = original.attribute(.font, at: (original.string as NSString).range(of: "Heading").location, effectiveRange: nil) as? NSFont
        try document.resolveAllRevisions(accepting: true)
        let joined = AttributedDocument.render(document)
        let joinedFont = joined.attribute(.font, at: (joined.string as NSString).range(of: "Heading").location, effectiveRange: nil) as? NSFont
        XCTAssertEqual(originalFont?.fontName, joinedFont?.fontName)
        XCTAssertEqual(originalFont?.pointSize, joinedFont?.pointSize)
        XCTAssertEqual(document.paragraphs[0].styleID, "normal")
    }
}
#endif
